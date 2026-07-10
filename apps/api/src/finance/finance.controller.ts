import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser, JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CreateExpenseDto } from './dto/create-expense.dto';
import { ExpenseResponse, FinanceSummaryResponse } from './finance.mapper';
import { FinanceService } from './finance.service';

/**
 * Finance endpoints (`/v1/finance/*`): a weekly spend summary and expense
 * logging. All require a Bearer token; the owner comes from the token.
 */
@UseGuards(JwtAuthGuard)
@Controller('finance')
export class FinanceController {
  constructor(private readonly finance: FinanceService) {}

  @Get('summary')
  summary(
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<FinanceSummaryResponse> {
    return this.finance.summary(user.id);
  }

  @Post('expenses')
  addExpense(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateExpenseDto,
  ): Promise<ExpenseResponse> {
    return this.finance.addExpense(user.id, dto);
  }
}
